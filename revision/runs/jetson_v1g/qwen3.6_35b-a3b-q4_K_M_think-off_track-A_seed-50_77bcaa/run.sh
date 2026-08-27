#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# Step 2: Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.fai" ] || [ ! -f "data/ref/chrM.fa.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Step 3-5: Per-sample alignment, sorting, indexing (idempotent)
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    
    if [ ! -f "$bai" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bai" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" \
        | samtools sort -@ $THREADS -o "$bam" -
        
        samtools index -@ $THREADS "$bam"
    fi
done

# Step 6-7: Per-sample variant calling, compression, indexing (idempotent)
for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    vcf_tbi="${vcf_gz}.tbi"
    
    if [ ! -f "$vcf_tbi" ] || [ "results/${sample}.bam" -nt "$vcf_tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref "$REF" \
            --out "results/${sample}.vcf" \
            --sig \
            --bonf \
            "results/${sample}.bam"
        
        bgzip -c "results/${sample}.vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        
        rm -f "results/${sample}.vcf"
    fi
done

# Step 8: Collapse VCFs into TSV (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=false

for sample in "${SAMPLES[@]}"; do
    vcf_tbi="results/${sample}.vcf.gz.tbi"
    if [ ! -f "$collapsed" ] || [ "$vcf_tbi" -nt "$collapsed" ]; then
        need_collapse=true
        break
    fi
done

if $need_collapse; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi