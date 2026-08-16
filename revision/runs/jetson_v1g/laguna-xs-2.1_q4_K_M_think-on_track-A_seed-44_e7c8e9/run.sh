#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for ext in amb ann bwt pac sa; do
    if [[ ! -f "data/ref/chrM.fa.$ext" ]]; then
        bwa index data/ref/chrM.fa
        break
    fi
done

# Per-sample processing
for sample in $SAMPLES; do
    bam="results/${sample}.bam"
    vcf_uncompressed="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    
    # Check if all outputs exist and are up to date
    need_run=false
    
    if [[ ! -f "$bam" ]]; then
        need_run=true
    elif [[ ! -f "${bam}.bai" ]]; then
        need_run=true
    elif [[ ! -f "$vcf_gz" ]] || [[ ! -f "${vcf_gz}.tbi" ]]; then
        need_run=true
    fi
    
    # Check if inputs are newer than outputs
    if [[ "$need_run" == false ]]; then
        fq1="data/raw/${sample}_1.fq.gz"
        fq2="data/raw/${sample}_2.fq.gz"
        ref_idx="data/ref/chrM.fa.bwt"
        
        if [[ "$fq1" -nt "$bam" ]] || [[ "$fq2" -nt "$bam" ]]; then
            need_run=true
        elif [[ "$ref_idx" -nt "$bam" ]]; then
            need_run=true
        fi
    fi
    
    if [[ "$need_run" == true ]]; then
        # Alignment with bwa mem
        bwa mem -t $THREADS \
            -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam"
        
        # BAM indexing
        samtools index -@ $THREADS "$bam"
        
        # Variant calling with lofreq
        lofreq call-parallel --pp-threads $THREADS \
            --ref data/ref/chrM.fa \
            --out "$vcf_uncompressed" \
            "$bam"
        
        # VCF compression and indexing
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

# Create collapsed.tsv if needed
collapsed="results/collapsed.tsv"
need_collapse=false

if [[ ! -f "$collapsed" ]]; then
    need_collapse=true
else
    for sample in $SAMPLES; do
        vcf_gz="results/${sample}.vcf.gz"
        if [[ "$vcf_gz" -nt "$collapsed" ]]; then
            need_collapse=true
            break
        fi
    done
fi

if [[ "$need_collapse" == true ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${sample}.vcf.gz" >> "$collapsed"
    done
fi

exit 0