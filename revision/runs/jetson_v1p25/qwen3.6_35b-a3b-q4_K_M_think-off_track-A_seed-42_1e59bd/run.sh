#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.amb ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# 3-7. Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if all outputs exist and are newer than inputs
    if [ -f "$bai" ] && [ -f "$tbi" ]; then
        fastq1="data/raw/${sample}_1.fq.gz"
        fastq2="data/raw/${sample}_2.fq.gz"
        ref="data/ref/chrM.fa"
        
        # Check if any input is newer than the newest output
        need_rebuild=false
        for f in "$bai" "$tbi"; do
            if [ "$fastq1" -nt "$f" ] || [ "$fastq2" -nt "$f" ] || [ "$ref" -nt "$f" ]; then
                need_rebuild=true
                break
            fi
        done
        
        if [ "$need_rebuild" = false ]; then
            continue
        fi
    fi

    # 3 & 4. Alignment and sorting
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam" -

    # 5. BAM indexing
    samtools index -@ $THREADS "$bam"

    # 6. Variant calling with lofreq
    vcf="results/${sample}.vcf"
    if [ ! -f "$vcf" ] || [ "$bam" -nt "$vcf" ]; then
        lofreq call-parallel --pp-threads $THREADS \
            -f data/ref/chrM.fa \
            -o "$vcf" \
            "$bam"
    fi

    # 7. VCF compression and indexing
    if [ ! -f "$vcf_gz" ] || [ "$vcf" -nt "$vcf_gz" ]; then
        bgzip -c "$vcf" > "$vcf_gz"
        rm -f "$vcf"
    fi
    
    if [ ! -f "$tbi" ] || [ "$vcf_gz" -nt "$tbi" ]; then
        tabix -p vcf "$vcf_gz"
    fi
done

# 8. Collapse step
collapsed="results/collapsed.tsv"
need_collapse=false

for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    if [ ! -f "$vcf_gz" ]; then
        need_collapse=true
        break
    fi
done

if [ -f "$collapsed" ]; then
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ "$vcf_gz" -nt "$collapsed" ]; then
            need_collapse=true
            break
        fi
    done
else
    need_collapse=true
fi

if [ "$need_collapse" = true ]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi